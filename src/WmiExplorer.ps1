using namespace System.Windows.Forms
using namespace System.Drawing
using namespace System.Collections
using namespace System.Management

class MainForm : Form {
    hidden [WmiClassTreeView] $_classTree

    MainForm () : Base() {
        $this.Width = 500
        $this.Height = 300

        $this.InstantiateLayout()
    }

    hidden [Void] InstantiateLayout () {
        $layout = [TableLayoutPanel]::new()
        $layout.Dock = [DockStyle]::Fill
        $layout.RowCount = 3

        $menuRow = [RowStyle]::new()
        $menuRow.Height = 25
        $menuRow.SizeType = [SizeType]::Absolute

        $contentRow = [RowStyle]::new()
        $contentRow.Height = 100
        $contentRow.SizeType = [SizeType]::Percent

        $statusRow = [RowStyle]::new()
        $statusRow.Height = 0
        $statusRow.SizeType = [SizeType]::Absolute

        $layout.RowStyles.Add($menuRow)
        $layout.RowStyles.Add($contentRow)
        $layout.RowStyles.Add($statusRow)

        $this.Controls.Add($layout)

        $contentSplit = [SplitContainer]::new()
        $contentSplit.Dock = [DockStyle]::Fill
        $contentSplit.Orientation = [Orientation]::Vertical

        $layout.Controls.Add($contentSplit, 0, 1)

        $this._classTree = [WmiClassTreeView]::new($contentSplit.Panel2)
        $contentSplit.Panel1.Controls.Add($this._classTree)
    }

    [DialogResult] ShowDialog() {
        if (!$this._classTree.isInitialized) {
            $this._classTree.Initialize()
        }

        return ([Form]$this).ShowDialog()
    }
}

class WmiClassTreeView : TreeView {
    hidden [Boolean] $_initialized = ($this | Add-Member -MemberType ScriptProperty -Name isInitialized -Value {
        #Getter
        return $this._initialized
    })
    hidden [Hashtable] $_callbacks = @{
        
    }

    [Control] $DisplayContainer

    WmiClassTreeView ([Control]$DisplayContainer) : Base() {
        $this.Dock = [DockStyle]::Fill

        $this.DisplayContainer = $DisplayContainer
    }

    [Void] Initialize () {
        $this.BeginUpdate()
        if ($this._initialized) { $this.Nodes.Clear() }

        $namespaces = Get-WmiObject -Namespace Root -Class __Namespace
        foreach ($namespace in $namespaces) {
            $node = [WmiNamespaceTreeNode]::new($namespace)
            $this.Nodes.Add($node)
            $namespace.Dispose()
        }
        
        $this._initialized = $true
        $this.EndUpdate()
    }

    [Void] OnClick ([EventArgs]$e) {
        # Ignore $e.Location as the coordinates are clipped to the client area of the treeview,
        # but treeview.GetNodeAt() expects full screen area coordinates.  Seems like an unusual
        # way to implement that functionality...

        # Get the TreeViewNode that was clicked (Right or Left)
        $clicked = $this.GetNodeAt($this.PointToClient([Control]::MousePosition))

        if ($clicked -ne $null) {
            $this.SelectedNode = $clicked

            if ($clicked -is [WmiNamespaceTreeNode] -and !$clicked.isInitialized) {
                $clicked.Initialize()
            }

            if ($clicked -is [WmiClassTreeNode]) {
                $clicked.Display($this.DisplayContainer)
            }
        }
    }
}

class WmiNamespaceTreeNode : TreeNode {
    hidden [Boolean] $_initialized = ($this | Add-Member -MemberType ScriptProperty -Name isInitialized -Value {
        #Getter
        return $this._initialized
    })

    WmiNamespaceTreeNode ([ManagementObject]$Namespace) : Base() {
        if ($Namespace.__CLASS -ne '__NAMESPACE') {
            throw [System.ArgumentException]::new()
        }

        $this.Text = $Namespace.Name
        $this.Name = $Namespace.__NAMESPACE
        # Set icon...
    }

    [Void] Initialize() {
        $this.TreeView.BeginUpdate()
        if ($this._initialized) { $this.Nodes.Clear() }

        $ns = "{0}\{1}" -f $this.Name, $this.Text
        $decendents = Get-WmiObject -Namespace $ns -Class __NAMESPACE
        foreach ($namespace in $decendents) {
            $childNode = [WmiNamespaceTreeNode]::new($namespace)
            $this.Nodes.Add($childNode)
            $namespace.Dispose()
        }

        foreach ($class in (Get-WmiObject -Namespace $ns -List)) {
            if ($class.__CLASS -eq '__NAMESPACE') {
                continue
            }

            $this.Nodes.Add([WmiClassTreeNode]::new($class))
            $class.Dispose()
        }

        $this._initialized = $true
        $this.TreeView.EndUpdate()
    }
}

class WmiClassTreeNode : TreeNode {
    WmiClassTreeNode ([ManagementClass]$Class) : Base() {
        if ($Class.__CLASS -eq '__NAMESPACE') {
            throw [System.ArgumentException]::new()
        }

        $this.Text = $Class.Name
        $this.Name = $Class.__NAMESPACE
        # Set icon...
    }

    [Void] Display ([Control]$Container) {
        $Container.Controls.Clear()
        $wmi = Get-WmiObject -Namespace $this.Name -Class $this.Text

        $layout = [SplitContainer]::new()
        $layout.Dock = [DockStyle]::Fill
        $layout.Orientation = [Orientation]::Vertical
        $layout.SplitterWidth = 5
        $layout.Panel1.BackColor = [Color]::AliceBlue
        $layout.Panel2.BackColor = [Color]::AliceBlue
        $layout.Panel1.AutoScroll = $true
        $layout.Panel2.AutoScroll = $true
        $layout.Panel1.Controls.Add([WmiClassPropertiesPanel]::new($wmi.Properties))

        $Container.Controls.Add($layout)
    }
}

class WmiClassPropertiesPanel : TableLayoutPanel {
    WmiClassPropertiesPanel ([PropertyDataCollection]$Properties) : Base() {
        $this.ColumnCount = 2

        [Graphics]$g = $this.CreateGraphics()
        $labelWidth = 0
        $valueWidth = 0
        
        $txtHeight = $g.MeasureString('W', $this.Font).Height + 1
        $this.Height = ($this.Margin.Top + $this.Margin.Bottom + $txtHeight) * ($Properties.Count + 1)

        $label = [Label]::new()
        $label.BackColor = [Color]::LightGray
        $label.TextAlign = [ContentAlignment]::MiddleCenter
        $label.Text = "Properties"
        $label.Dock = [DockStyle]::Fill
        $this.Controls.Add($label, 0, 0)
        $this.SetColumnSpan($label, 2)

        $i = 1
        foreach ($prop in $Properties) {
            # TODO: Properly handle arrays, and possibly nested data structures.
            if ($prop.IsArray) { continue }

            $size = $g.MeasureString($prop.Name, $this.Font)
            if ($size.Width -gt $labelWidth) { $labelWidth = $size.Width }

            $label = [Label]::new()
            $label.BackColor = [Color]::White
            $label.Text = $prop.Name
            $label.Dock = [DockStyle]::Fill
            $this.Controls.Add($label, 0, $i)


            $strValue = "$($prop.Value)"
            $size = $g.MeasureString($strValue, $this.Font)
            if ($size.Width -gt $valueWidth) { $valueWidth = $size.Width }

            $label = [Label]::new()
            $label.BackColor = [Color]::White
            $label.Text = $strValue
            $label.Dock = [DockStyle]::Fill
            $this.Controls.Add($label, 1, $i)

            $i++
        }
        
        $labelColStyle = [ColumnStyle]::new()
        $labelColStyle.Width = $this.Margin.Left + $this.Margin.Right + $labelWidth + 4
        $labelColStyle.SizeType = [SizeType]::Absolute

        $valueColStyle = [ColumnStyle]::new()
        $valueColStyle.Width = 100
        $valueColStyle.SizeType = [SizeType]::Percent

        $this.ColumnStyles.Add($labelColStyle)
        $this.ColumnStyles.Add($valueColStyle)

        $this.Width = $this.Margin.Left + $this.Margin.Right + $valueWidth + $labelWidth + 4
    }
}

$form = [MainForm]::new()
$form.ShowDialog()
$form.Dispose()
